import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

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
    if (!File(path).existsSync()) return false;
    return _handOff(path);
  }

  static Future<bool> _handOff(String target) async {
    try {
      if (Platform.isWindows) return _shellExecute(target);
      // `Process.start` with an argument LIST goes straight to execve — the
      // target is argv[1] and no shell ever sees it, so metacharacters in a
      // note's link are inert.
      await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [target]);
      return true;
    } catch (_) {
      return false; // no handler registered, or the launcher is missing
    }
  }

  /// Windows: `ShellExecuteW`, **not** `cmd /c start`.
  ///
  /// This replaced `Process.start('cmd', ['/c', 'start', '', target])`, and the
  /// reason is worth keeping. `cmd.exe` does not parse its command line the way
  /// the C runtime does: it applies its own metacharacter handling — `&`, `|`,
  /// `^`, `<`, `>` — to whatever it receives, *after* the ordinary argument
  /// quoting has been applied. Ordinary quoting therefore does not neutralise
  /// them. And `&` is perfectly legal in a URL (it separates query parameters),
  /// so the scheme allow-list above does not help either: a link in an imported
  /// or shared notebook could carry one.
  ///
  /// I have not demonstrated an exploit — that needs a Windows box this
  /// development environment does not have — and the claim here is deliberately
  /// the weaker one: **we were handing attacker-controlled text to a command
  /// interpreter, and there is no reason to.** `ShellExecuteW` is the actual
  /// Win32 API for "open this with its default handler". It takes the target as
  /// a single wide-string parameter, so there is no command line and nothing to
  /// parse. It is also what every other implementation of this function uses.
  ///
  /// Returns false on any failure code. `ShellExecuteW` reports success as an
  /// HINSTANCE greater than 32, which is a historical quirk rather than a typo.
  static bool _shellExecute(String target) {
    final op = 'open'.toNativeUtf16();
    final file = target.toNativeUtf16();
    try {
      final r = _shellExecuteW(0, op, file, nullptr, nullptr, _swShowNormal);
      return r > 32;
    } finally {
      calloc
        ..free(op)
        ..free(file);
    }
  }

  static const int _swShowNormal = 1;

  static final _shellExecuteW = DynamicLibrary.open('shell32.dll')
      .lookupFunction<
          IntPtr Function(IntPtr hwnd, Pointer<Utf16> operation,
              Pointer<Utf16> file, Pointer<Utf16> params,
              Pointer<Utf16> directory, Int32 showCmd),
          int Function(int hwnd, Pointer<Utf16> operation, Pointer<Utf16> file,
              Pointer<Utf16> params, Pointer<Utf16> directory,
              int showCmd)>('ShellExecuteW');
}
