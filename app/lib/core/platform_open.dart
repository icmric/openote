import 'package:flutter/foundation.dart' show visibleForTesting;

// The platform call lives in the native half; the web half opens a URL in a
// tab and answers false for local paths, which is already what this class
// documents for "no handler".
import 'platform_open_native.dart'
    if (dart.library.js_interop) 'platform_open_web.dart';

/// Hand a URL or a file to the operating system's default handler.
///
/// Deliberately dependency-free (no `url_launcher`): each desktop platform has
/// a one-line way to do this, and none of them needs a shell.
///
/// **That last part is the security property.** The targets that reach here
/// include URLs taken from *note text*, and note text is untrusted — an
/// imported OneNote page or a shared notebook can contain anything a stranger
/// wrote. So the rule is: the target is always passed as **one parameter to a
/// program**, never as a fragment of a command line that something else will
/// re-parse.
///
/// Used by external links in note text (TEXT-1) and by "open" on a file
/// attachment (MEDIA-2).
abstract final class PlatformOpen {
  /// Schemes we are willing to hand to the OS from *note content*.
  ///
  /// An allow-list, not a deny-list, for the reason above. In particular
  /// `file:` is excluded: a link in a note must not be able to launch a local
  /// executable.
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

  /// Extensions that run code rather than open in a viewer.
  ///
  /// Not an attempt at antivirus — it is the list a person would want to be
  /// asked about. Openote's own threat model says a shared or imported notebook
  /// "can contain anything a stranger wrote", and group notebooks over a shared
  /// folder are a shipped feature, so an attachment named `invoice.pdf.exe` is
  /// a thing a real notebook can carry. `safeFilename` scrubs path characters
  /// but deliberately keeps the extension, because the extension is what makes
  /// the file open in the right application.
  ///
  /// Double extensions are covered because only the LAST one decides what
  /// Windows runs.
  static const _executableExtensions = {
    '.exe', '.com', '.scr', '.pif', '.bat', '.cmd', '.msi', '.msp', '.cpl',
    '.jar', '.vbs', '.vbe', '.js', '.jse', '.wsf', '.wsh', '.ps1', '.psm1',
    '.reg', '.lnk', '.url', '.hta', '.sh', '.bash', '.zsh', '.command',
    '.app', '.dmg', '.pkg', '.deb', '.rpm', '.appimage', '.run', '.bin',
  };

  /// True when opening [name] would run something rather than show something.
  /// Callers ask the user first (style guide §7h).
  static bool isExecutableName(String name) {
    final n = name.trim().toLowerCase();
    final dot = n.lastIndexOf('.');
    return dot > 0 && _executableExtensions.contains(n.substring(dot));
  }

  /// Open a local file with whatever application owns its type.
  static Future<bool> file(String path) async {
    if (!platformFileExists(path)) return false;
    return _handOff(path);
  }

  /// Open a DIRECTORY in the file manager.
  ///
  /// Separate from [file] because that one's existence check is
  /// `File(path).existsSync()`, which is **false for a directory** — so the
  /// sync dialog's "Open folder" button handed it a folder, got `false` back,
  /// and did nothing at all. Reported as *"the open folder button doesnt work
  /// at all, ill press it and nothing happens"*.
  ///
  /// [file] keeps its stricter check rather than being widened: its other
  /// callers open an attachment or a video, where a directory is the wrong
  /// thing and refusing is correct.
  static Future<bool> folder(String path) async {
    if (!platformDirectoryExists(path)) return false;
    return _handOff(path);
  }

  /// **Test seam: what to do once a guard has passed.**
  ///
  /// Null is the real platform call. A test sets this so the POSITIVE case can
  /// be asserted at all — otherwise proving that [folder] opens a directory
  /// means actually opening one, which launches Explorer on a developer's
  /// machine and runs `xdg-open` against a temp directory on CI. The guards
  /// are the part worth pinning, and this is how they can be pinned in both
  /// directions rather than only where they refuse.
  @visibleForTesting
  static Future<bool> Function(String target)? debugHandOff;

  static Future<bool> _handOff(String target) async {
    final hook = debugHandOff;
    if (hook != null) return hook(target);
    return platformHandOff(target);
  }
}
