import 'dart:io';

/// Hand a URL or a file to the operating system's default handler.
///
/// Deliberately dependency-free (no `url_launcher`): the desktop platforms we
/// target all ship a one-line opener, and `Process.start` passes arguments as a
/// list — never through a shell — so nothing in a note's text can be injected as
/// a command.
///
/// Used by external links in note text (TEXT-1) and by "open" on a file
/// attachment (MEDIA-2).
abstract final class PlatformOpen {
  /// Schemes we are willing to hand to the OS from *note content*.
  ///
  /// Note text is untrusted — an imported OneNote page or a synced notebook can
  /// contain anything — so this is an allow-list, not a deny-list. In
  /// particular `file:` is excluded: a link in a note must not be able to launch
  /// a local executable.
  static const _allowedSchemes = {'http', 'https', 'mailto'};

  /// True when [raw] is a link we will open. Anything else is rendered as plain
  /// text rather than silently doing nothing.
  static bool isOpenableUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null &&
        uri.hasScheme &&
        _allowedSchemes.contains(uri.scheme.toLowerCase());
  }

  /// Open an external URL. Returns false if the scheme isn't allowed or the
  /// platform call failed — callers surface that rather than failing silently.
  static Future<bool> url(String raw) async {
    final trimmed = raw.trim();
    if (!isOpenableUrl(trimmed)) return false;
    return _handOff(trimmed);
  }

  /// Open a local file with whatever application owns its type.
  static Future<bool> file(String path) async {
    if (!File(path).existsSync()) return false;
    return _handOff(path);
  }

  static Future<bool> _handOff(String target) async {
    try {
      if (Platform.isWindows) {
        // `cmd /c start` needs an empty title argument first, or a quoted
        // target is consumed as the window title.
        await Process.start('cmd', ['/c', 'start', '', target],
            runInShell: false);
      } else if (Platform.isMacOS) {
        await Process.start('open', [target]);
      } else {
        await Process.start('xdg-open', [target]);
      }
      return true;
    } catch (_) {
      return false; // no handler registered, or the launcher is missing
    }
  }
}
